import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/services/apk_hardening_service.dart';

void main() {
  late Directory tempDirectory;
  late ApkHardeningService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('apk_hardening_');
    service = ApkHardeningService();
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'splits encrypts and restores multiple dex files byte-for-byte',
    () async {
      final decodedDirectory = Directory('${tempDirectory.path}/decoded');
      await decodedDirectory.create(recursive: true);
      final firstDex = Uint8List.fromList([
        ...utf8.encode('dex\n035\u0000'),
        ...List<int>.generate(31, (index) => index + 1),
      ]);
      final secondDex = Uint8List.fromList([
        ...utf8.encode('dex\n035\u0000'),
        ...List<int>.generate(23, (index) => 255 - index),
      ]);
      final firstDexFile = File('${decodedDirectory.path}/classes.dex');
      final secondDexFile = File('${decodedDirectory.path}/classes2.dex');
      await firstDexFile.writeAsBytes(firstDex, flush: true);
      await secondDexFile.writeAsBytes(secondDex, flush: true);

      final result = await service.buildEncryptedDexPayloadForTesting(
        decodedDirectory: decodedDirectory,
        dexFiles: [firstDexFile, secondDexFile],
        xorKey: Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
        partSizeBytes: 9,
      );

      expect(firstDexFile.existsSync(), isFalse);
      expect(secondDexFile.existsSync(), isFalse);
      expect(result.partCount, greaterThan(2));
      expect(result.totalSizeBytes, firstDex.length + secondDex.length);
      expect(
        result.totalSha256Hex,
        sha256.convert([...firstDex, ...secondDex]).toString(),
      );
      expect(
        result.apkEntryNames,
        everyElement(startsWith('assets/z1_guard/dex/')),
      );

      final restored = await service.decryptDexPayloadForTesting(
        decodedDirectory: decodedDirectory,
        encodedConfig: result.encodedConfig,
        xorKey: Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
      );

      expect(restored['classes.dex'], equals(firstDex));
      expect(restored['classes2.dex'], equals(secondDex));
    },
  );

  test('storage profile verifies hmac and detects tampering', () {
    final hmacKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    final xorKey = Uint8List.fromList([0x31, 0x42, 0x53, 0x64]);
    final entries = [
      ApkHardeningStorageProfileEntryForTesting(
        path: 'shared_prefs/user.xml',
        sizeBytes: 4,
        modifiedTimeMillis: 1001,
        sha256Hex: sha256.convert(utf8.encode('user')).toString(),
      ),
      ApkHardeningStorageProfileEntryForTesting(
        path: 'databases/app.db-wal',
        sizeBytes: 3,
        modifiedTimeMillis: 1002,
        sha256Hex: sha256.convert(utf8.encode('wal')).toString(),
      ),
    ];

    final profile = service.encodeStorageProfileForTesting(
      packageName: 'com.example.app',
      entries: entries,
      hmacKey: hmacKey,
      xorKey: xorKey,
    );

    expect(
      service.verifyStorageProfileForTesting(
        protectedProfileBytes: profile,
        packageName: 'com.example.app',
        expectedEntries: entries,
        hmacKey: hmacKey,
        xorKey: xorKey,
      ),
      isTrue,
    );

    final tamperedProfile = Uint8List.fromList(profile);
    tamperedProfile[tamperedProfile.length - 1] ^= 0x01;
    expect(
      service.verifyStorageProfileForTesting(
        protectedProfileBytes: tamperedProfile,
        packageName: 'com.example.app',
        expectedEntries: entries,
        hmacKey: hmacKey,
        xorKey: xorKey,
      ),
      isFalse,
    );

    final changedEntries = [
      entries.first,
      ApkHardeningStorageProfileEntryForTesting(
        path: 'databases/app.db-wal',
        sizeBytes: 7,
        modifiedTimeMillis: 1002,
        sha256Hex: sha256.convert(utf8.encode('changed')).toString(),
      ),
    ];
    expect(
      service.verifyStorageProfileForTesting(
        protectedProfileBytes: profile,
        packageName: 'com.example.app',
        expectedEntries: changedEntries,
        hmacKey: hmacKey,
        xorKey: xorKey,
      ),
      isFalse,
    );
  });

  test('storage protection tracks shared prefs and database files only', () {
    expect(
      service.isStorageProfileEntryPathForTesting('shared_prefs/user.xml'),
      isTrue,
    );
    expect(
      service.isStorageProfileEntryPathForTesting('databases/app.db'),
      isTrue,
    );
    expect(
      service.isStorageProfileEntryPathForTesting('databases/app.db-wal'),
      isTrue,
    );
    expect(
      service.isStorageProfileEntryPathForTesting('databases/app.db-shm'),
      isTrue,
    );
    expect(
      service.isStorageProfileEntryPathForTesting('databases/app.db-journal'),
      isTrue,
    );
    expect(
      service.isStorageProfileEntryPathForTesting(
        'no_backup/z1_guard/storage_profile.dat',
      ),
      isFalse,
    );
    expect(
      service.isStorageProfileEntryPathForTesting(
        'files/z1_guard/storage_profile.dat',
      ),
      isFalse,
    );
  });

  test('profile ignores only guard assets and signing generated entries', () {
    expect(
      service.shouldIgnoreIntegrityEntryForTesting('classes.dex', {
        'classes.dex',
        'assets/z1_guard/profile.dat',
      }),
      isTrue,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'assets/z1_guard/profile.dat',
        {'classes.dex', 'assets/z1_guard/profile.dat'},
      ),
      isTrue,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'assets/z1_guard/dex/dex_000_part_0000.bin',
        const {},
      ),
      isTrue,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'META-INF/MANIFEST.MF',
        const {},
      ),
      isTrue,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'META-INF/CERT.SF',
        const {},
      ),
      isTrue,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'META-INF/CERT.RSA',
        const {},
      ),
      isTrue,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'META-INF/inject.bin',
        const {},
      ),
      isFalse,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'META-INF/services/payload',
        const {},
      ),
      isFalse,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting(
        'lib/arm64-v8a/libinject.so',
        const {},
      ),
      isFalse,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting('assets/frida.js', const {}),
      isFalse,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting('classes2.dex', const {}),
      isFalse,
    );
    expect(
      service.shouldIgnoreIntegrityEntryForTesting('res/drawable/icon.png', {
        'classes.dex',
        'assets/z1_guard/profile.dat',
      }),
      isFalse,
    );
  });
}
