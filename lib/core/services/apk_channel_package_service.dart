import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ApkChannelPackageService {
  static const int defaultChannelBlockId = 0x71777777;

  Future<ApkChannelPackageResult> generate({
    required String sourceApkPath,
    required String outputApkPath,
    required String channelCode,
    int channelBlockId = defaultChannelBlockId,
  }) async {
    final sourceFile = File(sourceApkPath);
    if (!sourceFile.existsSync()) {
      throw ApkChannelPackageException('母包文件不存在：$sourceApkPath');
    }

    final outputFile = File(outputApkPath);
    await outputFile.parent.create(recursive: true);

    final sourceBytes = await sourceFile.readAsBytes();
    final outputBytes = buildChannelPackageBytes(
      sourceApkBytes: Uint8List.fromList(sourceBytes),
      channelCode: channelCode,
      channelBlockId: channelBlockId,
    );

    await outputFile.writeAsBytes(outputBytes, flush: true);

    return ApkChannelPackageResult(
      channelCode: channelCode,
      outputApkPath: outputApkPath,
      fileSizeBytes: outputBytes.length,
    );
  }

  Uint8List buildChannelPackageBytes({
    required Uint8List sourceApkBytes,
    required String channelCode,
    int channelBlockId = defaultChannelBlockId,
  }) {
    final normalizedChannel = channelCode.trim();
    if (normalizedChannel.isEmpty) {
      throw const ApkChannelPackageException('渠道码不能为空');
    }

    final eocdOffset = _findEndOfCentralDirectoryOffset(sourceApkBytes);
    final centralDirectoryOffset = _readUint32(sourceApkBytes, eocdOffset + 16);
    if (centralDirectoryOffset == 0xFFFFFFFF) {
      throw const ApkChannelPackageException('暂不支持 Zip64 APK，请使用普通 APK 包');
    }
    if (centralDirectoryOffset <= 0 ||
        centralDirectoryOffset > sourceApkBytes.length) {
      throw const ApkChannelPackageException(
        'APK ZIP 结构异常，无法定位 Central Directory',
      );
    }

    final signingBlock = _readSigningBlock(
      sourceApkBytes,
      centralDirectoryOffset,
    );
    final channelPayload = Uint8List.fromList(utf8.encode(normalizedChannel));
    final updatedBlock = _buildSigningBlock(
      signingBlock.pairs.where((pair) => pair.id != channelBlockId).followedBy([
        _SigningBlockPair(channelBlockId, channelPayload),
      ]).toList(),
    );

    final sizeDelta = updatedBlock.length - signingBlock.totalSize;
    final outputBytes = Uint8List(sourceApkBytes.length + sizeDelta);
    outputBytes.setRange(0, signingBlock.startOffset, sourceApkBytes);

    final newCentralDirectoryOffset =
        signingBlock.startOffset + updatedBlock.length;
    outputBytes.setRange(
      signingBlock.startOffset,
      newCentralDirectoryOffset,
      updatedBlock,
    );
    outputBytes.setRange(
      newCentralDirectoryOffset,
      outputBytes.length,
      sourceApkBytes,
      centralDirectoryOffset,
    );

    final newEocdOffset = eocdOffset + sizeDelta;
    _writeUint32(outputBytes, newEocdOffset + 16, newCentralDirectoryOffset);

    return outputBytes;
  }

  int _findEndOfCentralDirectoryOffset(Uint8List bytes) {
    const eocdMinLength = 22;
    const maxCommentLength = 0xFFFF;
    const eocdSignature = 0x06054B50;

    if (bytes.length < eocdMinLength) {
      throw const ApkChannelPackageException('APK 文件过小，无法识别 ZIP EOCD');
    }

    final minOffset = bytes.length - eocdMinLength - maxCommentLength;
    final stopOffset = minOffset < 0 ? 0 : minOffset;
    for (
      var offset = bytes.length - eocdMinLength;
      offset >= stopOffset;
      offset -= 1
    ) {
      if (_readUint32(bytes, offset) != eocdSignature) {
        continue;
      }

      final commentLength = _readUint16(bytes, offset + 20);
      final expectedLength = offset + eocdMinLength + commentLength;
      if (expectedLength == bytes.length) {
        return offset;
      }
    }

    throw const ApkChannelPackageException('无法定位 APK ZIP EOCD 记录');
  }

  _SigningBlock _readSigningBlock(Uint8List bytes, int centralDirectoryOffset) {
    if (centralDirectoryOffset < 32) {
      throw const ApkChannelPackageException(
        '母包缺少 APK Signing Block，请先使用 V2/V3 签名',
      );
    }

    final magicOffset = centralDirectoryOffset - _apkSigningBlockMagic.length;
    for (var index = 0; index < _apkSigningBlockMagic.length; index += 1) {
      if (bytes[magicOffset + index] != _apkSigningBlockMagic[index]) {
        throw const ApkChannelPackageException(
          '母包缺少 APK Signing Block，请先使用 V2/V3 签名',
        );
      }
    }

    final blockSize = _readUint64(bytes, centralDirectoryOffset - 24);
    final totalSize = blockSize + 8;
    final blockStartOffset = centralDirectoryOffset - totalSize;
    if (totalSize < 32 ||
        blockStartOffset < 0 ||
        blockStartOffset >= centralDirectoryOffset) {
      throw const ApkChannelPackageException('APK Signing Block 大小异常');
    }

    final headerSize = _readUint64(bytes, blockStartOffset);
    if (headerSize != blockSize) {
      throw const ApkChannelPackageException('APK Signing Block 头尾大小不一致');
    }

    final pairs = <_SigningBlockPair>[];
    var cursor = blockStartOffset + 8;
    final pairsEnd = centralDirectoryOffset - 24;
    while (cursor < pairsEnd) {
      if (pairsEnd - cursor < 12) {
        throw const ApkChannelPackageException('APK Signing Block pair 结构异常');
      }

      final pairLength = _readUint64(bytes, cursor);
      final pairStart = cursor + 8;
      final pairEnd = pairStart + pairLength;
      if (pairLength < 4 || pairEnd > pairsEnd) {
        throw const ApkChannelPackageException('APK Signing Block pair 大小异常');
      }

      final id = _readUint32(bytes, pairStart);
      final value = Uint8List.fromList(bytes.sublist(pairStart + 4, pairEnd));
      pairs.add(_SigningBlockPair(id, value));
      cursor = pairEnd;
    }

    if (cursor != pairsEnd) {
      throw const ApkChannelPackageException('APK Signing Block pair 未正确对齐');
    }

    return _SigningBlock(
      startOffset: blockStartOffset,
      totalSize: totalSize,
      pairs: pairs,
    );
  }

  Uint8List _buildSigningBlock(List<_SigningBlockPair> pairs) {
    final pairsBuilder = BytesBuilder(copy: false);
    for (final pair in pairs) {
      pairsBuilder.add(_buildPairBytes(pair));
    }

    final pairsBytes = pairsBuilder.toBytes();
    final blockSize = pairsBytes.length + 24;
    final totalSize = blockSize + 8;
    final blockBytes = Uint8List(totalSize);

    _writeUint64(blockBytes, 0, blockSize);
    blockBytes.setRange(8, 8 + pairsBytes.length, pairsBytes);
    _writeUint64(blockBytes, totalSize - 24, blockSize);
    blockBytes.setRange(
      totalSize - _apkSigningBlockMagic.length,
      totalSize,
      _apkSigningBlockMagic,
    );

    return blockBytes;
  }

  Uint8List _buildPairBytes(_SigningBlockPair pair) {
    final pairLength = pair.value.length + 4;
    final pairBytes = Uint8List(pairLength + 8);
    _writeUint64(pairBytes, 0, pairLength);
    _writeUint32(pairBytes, 8, pair.id);
    pairBytes.setRange(12, pairBytes.length, pair.value);
    return pairBytes;
  }

  int _readUint16(Uint8List bytes, int offset) {
    return ByteData.sublistView(
      bytes,
      offset,
      offset + 2,
    ).getUint16(0, Endian.little);
  }

  int _readUint32(Uint8List bytes, int offset) {
    return ByteData.sublistView(
      bytes,
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
  }

  int _readUint64(Uint8List bytes, int offset) {
    return ByteData.sublistView(
      bytes,
      offset,
      offset + 8,
    ).getUint64(0, Endian.little);
  }

  void _writeUint32(Uint8List bytes, int offset, int value) {
    ByteData.sublistView(
      bytes,
      offset,
      offset + 4,
    ).setUint32(0, value, Endian.little);
  }

  void _writeUint64(Uint8List bytes, int offset, int value) {
    ByteData.sublistView(
      bytes,
      offset,
      offset + 8,
    ).setUint64(0, value, Endian.little);
  }
}

class ApkChannelPackageResult {
  const ApkChannelPackageResult({
    required this.channelCode,
    required this.outputApkPath,
    required this.fileSizeBytes,
  });

  final String channelCode;
  final String outputApkPath;
  final int fileSizeBytes;
}

class ApkChannelPackageException implements Exception {
  const ApkChannelPackageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _SigningBlock {
  const _SigningBlock({
    required this.startOffset,
    required this.totalSize,
    required this.pairs,
  });

  final int startOffset;
  final int totalSize;
  final List<_SigningBlockPair> pairs;
}

class _SigningBlockPair {
  const _SigningBlockPair(this.id, this.value);

  final int id;
  final Uint8List value;
}

const List<int> _apkSigningBlockMagic = [
  0x41,
  0x50,
  0x4B,
  0x20,
  0x53,
  0x69,
  0x67,
  0x20,
  0x42,
  0x6C,
  0x6F,
  0x63,
  0x6B,
  0x20,
  0x34,
  0x32,
];
