import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/services/apk_channel_package_service.dart';

void main() {
  test('writes channel payload into APK Signing Block', () {
    final service = ApkChannelPackageService();
    final sourceBytes = _buildFakeApk();

    final outputBytes = service.buildChannelPackageBytes(
      sourceApkBytes: sourceBytes,
      channelCode: 'ch001',
    );

    expect(
      _readPairValue(
        outputBytes,
        ApkChannelPackageService.defaultChannelBlockId,
      ),
      'ch001',
    );
    expect(
      utf8.decode(
        outputBytes.sublist(
          _readCentralDirectoryOffset(outputBytes),
          _readCentralDirectoryOffset(outputBytes) + 'CENTRAL'.length,
        ),
      ),
      'CENTRAL',
    );
    expect(outputBytes.length, greaterThan(sourceBytes.length));
  });

  test('replaces existing channel payload instead of duplicating it', () {
    final service = ApkChannelPackageService();
    final sourceBytes = _buildFakeApk(channelCode: 'old');

    final outputBytes = service.buildChannelPackageBytes(
      sourceApkBytes: sourceBytes,
      channelCode: 'ch099',
    );

    expect(
      _readPairValue(
        outputBytes,
        ApkChannelPackageService.defaultChannelBlockId,
      ),
      'ch099',
    );
    expect(
      _countPairs(outputBytes, ApkChannelPackageService.defaultChannelBlockId),
      1,
    );
  });

  test('throws when the APK does not contain a V2/V3 signing block', () {
    final service = ApkChannelPackageService();

    expect(
      () => service.buildChannelPackageBytes(
        sourceApkBytes: _buildZipWithoutSigningBlock(),
        channelCode: 'ch001',
      ),
      throwsA(isA<ApkChannelPackageException>()),
    );
  });
}

Uint8List _buildFakeApk({String? channelCode}) {
  final prefix = Uint8List.fromList(utf8.encode('LOCAL_FILE_DATA'));
  final pairs = [
    _Pair(0x01020304, Uint8List.fromList(utf8.encode('signature'))),
    if (channelCode != null)
      _Pair(
        ApkChannelPackageService.defaultChannelBlockId,
        Uint8List.fromList(utf8.encode(channelCode)),
      ),
  ];
  final signingBlock = _buildSigningBlock(pairs);
  final centralDirectory = Uint8List.fromList(utf8.encode('CENTRAL_DIRECTORY'));
  final eocd = _buildEocd(
    centralDirectoryOffset: prefix.length + signingBlock.length,
    centralDirectorySize: centralDirectory.length,
  );

  return _concat([prefix, signingBlock, centralDirectory, eocd]);
}

Uint8List _buildZipWithoutSigningBlock() {
  final prefix = Uint8List.fromList(utf8.encode('LOCAL_FILE_DATA'));
  final centralDirectory = Uint8List.fromList(utf8.encode('CENTRAL_DIRECTORY'));
  final eocd = _buildEocd(
    centralDirectoryOffset: prefix.length,
    centralDirectorySize: centralDirectory.length,
  );

  return _concat([prefix, centralDirectory, eocd]);
}

Uint8List _buildSigningBlock(List<_Pair> pairs) {
  final pairBytes = pairs.map(_buildPair).toList();
  final pairsLength = pairBytes.fold<int>(
    0,
    (sum, bytes) => sum + bytes.length,
  );
  final blockSize = pairsLength + 24;
  final totalSize = blockSize + 8;
  final block = Uint8List(totalSize);

  _writeUint64(block, 0, blockSize);
  var cursor = 8;
  for (final bytes in pairBytes) {
    block.setRange(cursor, cursor + bytes.length, bytes);
    cursor += bytes.length;
  }
  _writeUint64(block, totalSize - 24, blockSize);
  block.setRange(totalSize - _magic.length, totalSize, _magic);

  return block;
}

Uint8List _buildPair(_Pair pair) {
  final pairLength = pair.value.length + 4;
  final bytes = Uint8List(pairLength + 8);
  _writeUint64(bytes, 0, pairLength);
  _writeUint32(bytes, 8, pair.id);
  bytes.setRange(12, bytes.length, pair.value);
  return bytes;
}

Uint8List _buildEocd({
  required int centralDirectoryOffset,
  required int centralDirectorySize,
}) {
  final eocd = Uint8List(22);
  _writeUint32(eocd, 0, 0x06054B50);
  _writeUint16(eocd, 8, 1);
  _writeUint16(eocd, 10, 1);
  _writeUint32(eocd, 12, centralDirectorySize);
  _writeUint32(eocd, 16, centralDirectoryOffset);
  return eocd;
}

String? _readPairValue(Uint8List bytes, int id) {
  final pairs = _readPairs(bytes);
  final value = pairs[id];
  return value == null ? null : utf8.decode(value);
}

int _countPairs(Uint8List bytes, int id) {
  var count = 0;
  for (final pairId in _readPairIds(bytes)) {
    if (pairId == id) {
      count += 1;
    }
  }

  return count;
}

Map<int, Uint8List> _readPairs(Uint8List bytes) {
  final pairs = <int, Uint8List>{};
  final centralDirectoryOffset = _readCentralDirectoryOffset(bytes);
  var cursor = _readSigningBlockStart(bytes) + 8;
  final pairsEnd = centralDirectoryOffset - 24;

  while (cursor < pairsEnd) {
    final pairLength = _readUint64(bytes, cursor);
    final pairStart = cursor + 8;
    final pairEnd = pairStart + pairLength;
    final id = _readUint32(bytes, pairStart);
    pairs[id] = Uint8List.fromList(bytes.sublist(pairStart + 4, pairEnd));
    cursor = pairEnd;
  }

  return pairs;
}

List<int> _readPairIds(Uint8List bytes) {
  final ids = <int>[];
  final centralDirectoryOffset = _readCentralDirectoryOffset(bytes);
  var cursor = _readSigningBlockStart(bytes) + 8;
  final pairsEnd = centralDirectoryOffset - 24;

  while (cursor < pairsEnd) {
    final pairLength = _readUint64(bytes, cursor);
    final pairStart = cursor + 8;
    ids.add(_readUint32(bytes, pairStart));
    cursor = pairStart + pairLength;
  }

  return ids;
}

int _readSigningBlockStart(Uint8List bytes) {
  final centralDirectoryOffset = _readCentralDirectoryOffset(bytes);
  final blockSize = _readUint64(bytes, centralDirectoryOffset - 24);
  return centralDirectoryOffset - blockSize - 8;
}

int _readCentralDirectoryOffset(Uint8List bytes) {
  final eocdOffset = bytes.length - 22;
  return _readUint32(bytes, eocdOffset + 16);
}

Uint8List _concat(List<Uint8List> chunks) {
  final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  final output = Uint8List(totalLength);
  var cursor = 0;
  for (final chunk in chunks) {
    output.setRange(cursor, cursor + chunk.length, chunk);
    cursor += chunk.length;
  }

  return output;
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

void _writeUint16(Uint8List bytes, int offset, int value) {
  ByteData.sublistView(
    bytes,
    offset,
    offset + 2,
  ).setUint16(0, value, Endian.little);
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

class _Pair {
  const _Pair(this.id, this.value);

  final int id;
  final Uint8List value;
}

const List<int> _magic = [
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
