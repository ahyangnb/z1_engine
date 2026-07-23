import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/models/hardening_artifact.dart';
import 'package:z1_engine/core/services/hardening_artifact_inspector.dart';

void main() {
  late Directory tempDirectory;
  late HardeningArtifactInspector inspector;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'hardening_artifact_',
    );
    inspector = HardeningArtifactInspector();
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('recognizes APK by archive contents', () async {
    final apk = File('${tempDirectory.path}/sample.apk');
    await apk.writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('AndroidManifest.xml', 'manifest'))
          ..addFile(ArchiveFile.string('classes.dex', 'dex')),
      ),
    );

    final result = await inspector.inspect(apk.path);

    expect(result.type, HardeningArtifactType.apk);
  });

  test('recognizes AAB and returns sorted module names', () async {
    final aab = File('${tempDirectory.path}/sample.aab');
    await aab.writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('BundleConfig.pb', 'config'))
          ..addFile(
            ArchiveFile.string(
              'feature/manifest/AndroidManifest.xml',
              'feature',
            ),
          )
          ..addFile(
            ArchiveFile.string('base/manifest/AndroidManifest.xml', 'base'),
          ),
      ),
    );

    final result = await inspector.inspect(aab.path);

    expect(result.type, HardeningArtifactType.aab);
    expect(result.moduleNames, ['base', 'feature']);
  });

  test('rejects archive extension and contents mismatch', () async {
    final fakeAab = File('${tempDirectory.path}/sample.aab');
    await fakeAab.writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('AndroidManifest.xml', 'manifest')),
      ),
    );

    expect(
      () => inspector.inspect(fakeAab.path),
      throwsA(
        isA<HardeningArtifactException>().having(
          (error) => error.message,
          'message',
          contains('内容是 APK'),
        ),
      ),
    );
  });

  test('recognizes Android ELF shared object and ABI', () async {
    final so = File('${tempDirectory.path}/libsample.so');
    final header = Uint8List(64)
      ..setAll(0, [0x7f, 0x45, 0x4c, 0x46])
      ..[4] = 2
      ..[5] = 1
      ..[16] = 3
      ..[18] = 183;
    await so.writeAsBytes(header);

    final result = await inspector.inspect(so.path);

    expect(result.type, HardeningArtifactType.sharedObject);
    expect(result.abi, 'arm64-v8a');
  });

  test('rejects non ELF file with so extension', () async {
    final so = File('${tempDirectory.path}/invalid.so');
    await so.writeAsString('not elf');

    expect(
      () => inspector.inspect(so.path),
      throwsA(isA<HardeningArtifactException>()),
    );
  });
}
