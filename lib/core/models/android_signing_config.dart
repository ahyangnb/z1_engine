enum AndroidSigningScheme {
  automatic('自动选择'),
  v1('V1 (APK Signature Scheme v1)'),
  v2('V2 (APK Signature Scheme v2, 包含V1)'),
  v2Only('V2 Only (APK Signature Scheme v2, 不含V1)'),
  v3('V3 (APK Signature Scheme v3, 包含V1和V2)');

  const AndroidSigningScheme(this.label);

  final String label;
}

class AndroidSigningConfig {
  const AndroidSigningConfig({
    required this.id,
    required this.name,
    required this.keystorePath,
    required this.keyAlias,
    required this.storePassword,
    required this.keyPassword,
    this.zipalignPath = '',
    this.apksignerPath = '',
    this.nativeLibraryPageAlignmentKb = 16,
    this.signingScheme = AndroidSigningScheme.v2,
  });

  final String id;
  final String name;
  final String keystorePath;
  final String keyAlias;
  final String storePassword;
  final String keyPassword;
  final String zipalignPath;
  final String apksignerPath;
  final int nativeLibraryPageAlignmentKb;
  final AndroidSigningScheme signingScheme;

  bool get usesExplicitSigningScheme {
    return signingScheme != AndroidSigningScheme.automatic;
  }

  bool get enableV1Signing {
    return switch (signingScheme) {
      AndroidSigningScheme.automatic => false,
      AndroidSigningScheme.v1 => true,
      AndroidSigningScheme.v2 => true,
      AndroidSigningScheme.v2Only => false,
      AndroidSigningScheme.v3 => true,
    };
  }

  bool get enableV2Signing {
    return switch (signingScheme) {
      AndroidSigningScheme.automatic => false,
      AndroidSigningScheme.v1 => false,
      AndroidSigningScheme.v2 => true,
      AndroidSigningScheme.v2Only => true,
      AndroidSigningScheme.v3 => true,
    };
  }

  bool get enableV3Signing {
    return switch (signingScheme) {
      AndroidSigningScheme.automatic => false,
      AndroidSigningScheme.v1 => false,
      AndroidSigningScheme.v2 => false,
      AndroidSigningScheme.v2Only => false,
      AndroidSigningScheme.v3 => true,
    };
  }

  bool get enableV4Signing {
    return false;
  }

  String get effectiveKeyPassword {
    final normalizedKeyPassword = keyPassword.trim();
    return normalizedKeyPassword.isEmpty
        ? storePassword
        : normalizedKeyPassword;
  }

  String get effectiveApksignerPath {
    final normalizedApksignerPath = apksignerPath.trim();
    return normalizedApksignerPath.isEmpty
        ? 'apksigner'
        : normalizedApksignerPath;
  }

  String get effectiveZipalignPath {
    final normalizedZipalignPath = zipalignPath.trim();
    return normalizedZipalignPath.isEmpty ? 'zipalign' : normalizedZipalignPath;
  }
}
