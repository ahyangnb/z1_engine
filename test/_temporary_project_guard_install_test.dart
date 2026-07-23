import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/code_transparency_signing_config.dart';
import 'package:z1_engine/core/services/aab_project_hardening_installer.dart';

void main() {
  test('install real project guard fixture', () async {
    final installer = AabProjectHardeningInstaller(
      bundletoolLoader: () async => Uint8List.fromList(
        await File(
          'assets/tools/bundletool-all-1.18.3.jar',
        ).readAsBytes(),
      ),
    );
    final result = await installer.install(
      projectPath: '/tmp/z1-project-guard.S5foeI/app',
      uploadSigningConfig: AndroidSigningConfig(
        id: 'upload',
        name: 'upload',
        keystorePath: '/tmp/z1-aab-integration.hRyb1z/upload.p12',
        keyAlias: 'upload',
        storePassword: Platform.environment['Z1_UPLOAD_TEST_PASS']!,
        keyPassword: Platform.environment['Z1_UPLOAD_TEST_PASS']!,
      ),
      transparencySigningConfig: CodeTransparencySigningConfig(
        id: 'transparency',
        name: 'transparency',
        keystorePath: '/tmp/z1-aab-integration.hRyb1z/transparency.p12',
        keyAlias: 'transparency',
        storePassword: Platform.environment['Z1_TRANSPARENCY_TEST_PASS']!,
        keyPassword: Platform.environment['Z1_TRANSPARENCY_TEST_PASS']!,
      ),
      playCertificateSha256: [
        '3333333333333333333333333333333333333333333333333333333333333333',
      ],
    );
    expect(result.originalApplicationName, 'android.app.Application');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
