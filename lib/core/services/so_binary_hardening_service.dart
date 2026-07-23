import 'dart:io';

import 'package:z1_engine/core/models/hardening_artifact.dart';
import 'package:z1_engine/core/services/android_toolchain_resolver.dart';
import 'package:z1_engine/core/services/hardening_artifact_inspector.dart';

class SoBinaryHardeningService {
  SoBinaryHardeningService({
    AndroidToolchainResolver? toolchain,
    HardeningArtifactInspector? inspector,
  }) : _toolchain = toolchain ?? AndroidToolchainResolver(),
       _inspector = inspector ?? HardeningArtifactInspector();

  final AndroidToolchainResolver _toolchain;
  final HardeningArtifactInspector _inspector;

  Future<SoBinaryHardeningResult> harden({
    required String sourceSoPath,
    required String outputSoPath,
    bool saveDebugSymbols = true,
  }) async {
    final sourceFile = File(sourceSoPath);
    if (!await sourceFile.exists()) {
      throw SoBinaryHardeningException('SO 文件不存在：$sourceSoPath');
    }
    final outputFile = File(outputSoPath);
    if (sourceFile.absolute.path == outputFile.absolute.path) {
      throw const SoBinaryHardeningException('输出路径不能与源 SO 相同');
    }

    final inspection = await _inspector.inspect(sourceFile.path);
    if (inspection.type != HardeningArtifactType.sharedObject) {
      throw const SoBinaryHardeningException('输入文件不是 Android SO');
    }

    final logs = <String>['识别 ABI：${inspection.abi}'];
    final llvmReadelf = _toolchain.resolveNdkTool('llvm-readelf');
    final llvmStrip = _toolchain.resolveNdkTool('llvm-strip');
    final llvmObjcopy = _toolchain.resolveNdkTool('llvm-objcopy');
    logs.add('llvm-readelf：$llvmReadelf');
    logs.add('llvm-strip：$llvmStrip');

    final before = await _readElfSnapshot(llvmReadelf, sourceFile.path);
    final workDirectory = await Directory.systemTemp.createTemp(
      'z1_so_harden_',
    );
    final workingSo = File(_joinPath(workDirectory.path, 'working.so'));
    final workingDebug = File(_joinPath(workDirectory.path, 'working.so.dbg'));

    try {
      await sourceFile.copy(workingSo.path);
      if (saveDebugSymbols) {
        await _runChecked(llvmObjcopy, [
          '--only-keep-debug',
          sourceFile.path,
          workingDebug.path,
        ], label: '提取调试符号');
      }
      await _runChecked(llvmStrip, [
        '--strip-debug',
        workingSo.path,
      ], label: '去除调试符号');

      final after = await _readElfSnapshot(llvmReadelf, workingSo.path);
      final mismatch = before.compatibilityDifference(after);
      if (mismatch != null) {
        throw SoBinaryHardeningException('strip 后 ELF 兼容信息发生变化：$mismatch');
      }

      await outputFile.parent.create(recursive: true);
      final temporaryOutput = File('${outputFile.path}.z1tmp');
      if (await temporaryOutput.exists()) {
        await temporaryOutput.delete();
      }
      await workingSo.copy(temporaryOutput.path);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await temporaryOutput.rename(outputFile.path);

      String? debugSymbolsPath;
      if (saveDebugSymbols) {
        final debugFile = File('${outputFile.path}.dbg');
        final temporaryDebug = File('${debugFile.path}.z1tmp');
        if (await temporaryDebug.exists()) {
          await temporaryDebug.delete();
        }
        await workingDebug.copy(temporaryDebug.path);
        if (await debugFile.exists()) {
          await debugFile.delete();
        }
        await temporaryDebug.rename(debugFile.path);
        debugSymbolsPath = debugFile.path;
      }

      logs.add('动态导出符号保持不变：${after.exportedSymbols.length} 个');
      logs.add('依赖库保持不变：${after.neededLibraries.join('、')}');
      logs.add(after.hasRelro ? 'GNU RELRO：已启用' : 'GNU RELRO：未检测到');
      logs.add(after.hasNonExecutableStack ? 'NX Stack：已启用' : 'NX Stack：未检测到');
      logs.add(after.bindNow ? 'BIND_NOW：已启用' : 'BIND_NOW：未启用');
      logs.add(after.hasTextRelocations ? '警告：检测到 TEXTREL' : 'TEXTREL：未检测到');
      logs.add('SO 兼容加固完成：${outputFile.path}');

      return SoBinaryHardeningResult(
        outputSoPath: outputFile.path,
        debugSymbolsPath: debugSymbolsPath,
        abi: inspection.abi!,
        snapshot: after,
        logs: logs,
      );
    } on AndroidToolchainException catch (error) {
      throw SoBinaryHardeningException(error.message);
    } finally {
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  Future<SoElfSnapshot> inspectForTesting(String readelfOutput) async {
    return _parseReadelfOutput(readelfOutput);
  }

  Future<SoElfSnapshot> _readElfSnapshot(
    String llvmReadelf,
    String path,
  ) async {
    final result = await Process.run(llvmReadelf, [
      '--file-header',
      '--program-headers',
      '--dynamic',
      '--dyn-syms',
      '--wide',
      path,
    ]);
    if (result.exitCode != 0) {
      throw SoBinaryHardeningException(
        '读取 ELF 失败：${result.stderr.toString().trim()}',
      );
    }
    return _parseReadelfOutput(result.stdout.toString());
  }

  SoElfSnapshot _parseReadelfOutput(String output) {
    String valueAfter(String label) {
      for (final line in output.split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.startsWith('$label:')) {
          return trimmed.substring(label.length + 1).trim();
        }
      }
      return '';
    }

    final neededLibraries = RegExp(
      r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]',
    ).allMatches(output).map((match) => match.group(1)!).toSet();
    final sonameMatch = RegExp(
      r'\(SONAME\)\s+Library soname: \[([^\]]+)\]',
    ).firstMatch(output);
    final exportedSymbols = <String>{};
    final symbolLine = RegExp(
      r'^\s*\d+:\s+[0-9a-fA-F]+\s+\d+\s+\S+\s+(GLOBAL|WEAK)\s+\S+\s+(\S+)\s+(.+?)\s*$',
    );
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = symbolLine.firstMatch(line);
      if (match == null || match.group(2) == 'UND') {
        continue;
      }
      final name = match.group(3)!.trim().split(RegExp(r'\s+')).first;
      if (name.isNotEmpty) {
        exportedSymbols.add(name);
      }
    }

    final stackLine = output
        .split(RegExp(r'\r?\n'))
        .where((line) => line.contains('GNU_STACK'))
        .cast<String?>()
        .firstWhere((line) => line != null, orElse: () => null);
    final hasExecutableStack =
        stackLine != null && RegExp(r'\bRWE\b').hasMatch(stackLine);

    return SoElfSnapshot(
      elfClass: valueAfter('Class'),
      dataEncoding: valueAfter('Data'),
      elfType: valueAfter('Type'),
      machine: valueAfter('Machine'),
      soname: sonameMatch?.group(1),
      neededLibraries: neededLibraries,
      exportedSymbols: exportedSymbols,
      hasRelro: output.contains('GNU_RELRO'),
      hasNonExecutableStack: stackLine != null && !hasExecutableStack,
      bindNow:
          output.contains('(BIND_NOW)') ||
          output
              .split(RegExp(r'\r?\n'))
              .any(
                (line) =>
                    (line.contains('(FLAGS)') || line.contains('(FLAGS_1)')) &&
                    line.contains('NOW'),
              ),
      hasTextRelocations: output.contains('(TEXTREL)'),
    );
  }

  Future<void> _runChecked(
    String executable,
    List<String> arguments, {
    required String label,
  }) async {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      final output = [
        result.stdout.toString().trim(),
        result.stderr.toString().trim(),
      ].where((value) => value.isNotEmpty).join('\n');
      throw SoBinaryHardeningException('$label 失败：$output');
    }
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith('/') || parent.endsWith(r'\')) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }
}

class SoElfSnapshot {
  const SoElfSnapshot({
    required this.elfClass,
    required this.dataEncoding,
    required this.elfType,
    required this.machine,
    required this.soname,
    required this.neededLibraries,
    required this.exportedSymbols,
    required this.hasRelro,
    required this.hasNonExecutableStack,
    required this.bindNow,
    required this.hasTextRelocations,
  });

  final String elfClass;
  final String dataEncoding;
  final String elfType;
  final String machine;
  final String? soname;
  final Set<String> neededLibraries;
  final Set<String> exportedSymbols;
  final bool hasRelro;
  final bool hasNonExecutableStack;
  final bool bindNow;
  final bool hasTextRelocations;

  String? compatibilityDifference(SoElfSnapshot other) {
    if (elfClass != other.elfClass) return 'ELF Class';
    if (dataEncoding != other.dataEncoding) return 'Data Encoding';
    if (elfType != other.elfType) return 'ELF Type';
    if (machine != other.machine) return 'Machine';
    if (soname != other.soname) return 'SONAME';
    if (!_sameSet(neededLibraries, other.neededLibraries)) return 'DT_NEEDED';
    if (!_sameSet(exportedSymbols, other.exportedSymbols)) return '动态导出符号';
    return null;
  }

  bool _sameSet(Set<String> left, Set<String> right) {
    return left.length == right.length && left.containsAll(right);
  }
}

class SoBinaryHardeningResult {
  const SoBinaryHardeningResult({
    required this.outputSoPath,
    required this.debugSymbolsPath,
    required this.abi,
    required this.snapshot,
    required this.logs,
  });

  final String outputSoPath;
  final String? debugSymbolsPath;
  final String abi;
  final SoElfSnapshot snapshot;
  final List<String> logs;
}

class SoBinaryHardeningException implements Exception {
  const SoBinaryHardeningException(this.message);

  final String message;

  @override
  String toString() => message;
}
