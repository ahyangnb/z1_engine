import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/code_transparency_signing_config.dart';
import 'package:z1_engine/core/services/aab_project_hardening_installer.dart';
import 'package:z1_engine/core/services/apk_hardening_service.dart';

String _certificate(String byte) => List.filled(32, byte).join();

void main() {
  late Directory tempDirectory;
  late Directory androidDirectory;
  late File manifestFile;
  late File buildFile;
  late AabProjectHardeningInstaller installer;

  const uploadConfig = AndroidSigningConfig(
    id: 'upload',
    name: 'upload',
    keystorePath: '/tmp/upload.jks',
    keyAlias: 'upload',
    storePassword: 'store',
    keyPassword: 'key',
  );
  const transparencyConfig = CodeTransparencySigningConfig(
    id: 'transparency',
    name: 'transparency',
    keystorePath: '/tmp/transparency.jks',
    keyAlias: 'transparency',
    storePassword: 'store2',
    keyPassword: 'key2',
  );

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('aab_project_guard_');
    androidDirectory = Directory('${tempDirectory.path}/android');
    await Directory(
      '${androidDirectory.path}/app/src/main',
    ).create(recursive: true);
    manifestFile = File(
      '${androidDirectory.path}/app/src/main/AndroidManifest.xml',
    );
    buildFile = File('${androidDirectory.path}/app/build.gradle');
    await manifestFile.writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">
    <application android:name=".App" android:label="Example"></application>
</manifest>
''');
    await buildFile.writeAsString('''
plugins {
    id "com.android.application"
}
android {
    namespace "com.example.app"
}
''');

    installer = AabProjectHardeningInstaller(
      guardDexBuilder:
          ({
            required String outputDexPath,
            required String originalApplicationName,
            required List<String> acceptedCertificateSha256,
          }) async {
            await File(outputDexPath).writeAsBytes([0x64, 0x65, 0x78]);
            return const ApkProjectGuardDexResult(
              outputDexPath: 'guard.dex',
              dexXorKeyHex: '00112233445566778899aabbccddeeff',
              aabCodeHmacKeyHex:
                  '00112233445566778899aabbccddeeff'
                  '00112233445566778899aabbccddeeff',
              logs: ['guard dex test'],
            );
          },
      certificateReader:
          ({
            required String keystorePath,
            required String keyAlias,
            required String storePassword,
          }) async {
            return keyAlias == 'upload'
                ? _certificate('11')
                : _certificate('22');
          },
      bundletoolLoader: () async {
        return Uint8List.fromList(
          await File('assets/tools/bundletool-all-1.18.3.jar').readAsBytes(),
        );
      },
    );
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('installs idempotently and removes with exact restoration', () async {
    final originalManifest = await manifestFile.readAsString();
    final originalBuild = await buildFile.readAsString();

    final first = await installer.install(
      projectPath: tempDirectory.path,
      uploadSigningConfig: uploadConfig,
      transparencySigningConfig: transparencyConfig,
      playCertificateSha256: [_certificate('33').replaceFirst('3333', '33:33')],
    );
    final second = await installer.install(
      projectPath: tempDirectory.path,
      uploadSigningConfig: uploadConfig,
      transparencySigningConfig: transparencyConfig,
      playCertificateSha256: [_certificate('33')],
    );

    expect(first.originalApplicationName, 'com.example.app.App');
    expect(second.logs, contains(contains('已有 AAB Guard')));
    expect(
      await manifestFile.readAsString(),
      contains('com.z1.guard.Z1GuardApplication'),
    );
    expect(
      await manifestFile.readAsString(),
      contains('com.z1.guard.Z1GuardProvider'),
    );
    expect(await buildFile.readAsString(), contains('z1_aab_guard.gradle'));
    expect(
      File('${androidDirectory.path}/z1_guard/guard.dex').existsSync(),
      isTrue,
    );
    expect(
      File(
        '${androidDirectory.path}/z1_guard/local.properties',
      ).readAsStringSync(),
      isNot(contains('Play')),
    );

    await installer.remove(projectPath: tempDirectory.path);

    expect(await manifestFile.readAsString(), originalManifest);
    expect(await buildFile.readAsString(), originalBuild);
    expect(
      Directory('${androidDirectory.path}/z1_guard').existsSync(),
      isFalse,
    );
  });

  test('refuses removal after user edits managed manifest', () async {
    await installer.install(
      projectPath: tempDirectory.path,
      uploadSigningConfig: uploadConfig,
      transparencySigningConfig: transparencyConfig,
      playCertificateSha256: [_certificate('33')],
    );
    await manifestFile.writeAsString(
      '${await manifestFile.readAsString()}\n<!-- user edit -->\n',
    );

    expect(
      () => installer.remove(projectPath: tempDirectory.path),
      throwsA(isA<AabProjectHardeningException>()),
    );
  });
}
