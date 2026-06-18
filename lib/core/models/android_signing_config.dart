enum AndroidSigningScheme {
  automatic('自动选择'),
  v1('V1 (APK Signature Scheme v1)'),
  v2('V2 (APK Signature Scheme v2, 包含V1)'),
  v2Only('V2 Only (APK Signature Scheme v2, 不含V1)'),
  v3('V3 (APK Signature Scheme v3, 包含V1和V2)');

  const AndroidSigningScheme(this.label);

  final String label;

  static AndroidSigningScheme fromName(String? name) {
    for (final scheme in AndroidSigningScheme.values) {
      if (scheme.name == name) {
        return scheme;
      }
    }

    return AndroidSigningScheme.v2;
  }
}

class AndroidSigningConfig {
  const AndroidSigningConfig({
    required this.id,
    required this.name,
    required this.keystorePath,
    required this.keyAlias,
    required this.storePassword,
    required this.keyPassword,
    this.remark = '',
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
  final String remark;
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

  AndroidSigningConfig copyWith({
    String? name,
    String? keystorePath,
    String? keyAlias,
    String? storePassword,
    String? keyPassword,
    String? remark,
    String? zipalignPath,
    String? apksignerPath,
    int? nativeLibraryPageAlignmentKb,
    AndroidSigningScheme? signingScheme,
  }) {
    return AndroidSigningConfig(
      id: id,
      name: name ?? this.name,
      keystorePath: keystorePath ?? this.keystorePath,
      keyAlias: keyAlias ?? this.keyAlias,
      storePassword: storePassword ?? this.storePassword,
      keyPassword: keyPassword ?? this.keyPassword,
      remark: remark ?? this.remark,
      zipalignPath: zipalignPath ?? this.zipalignPath,
      apksignerPath: apksignerPath ?? this.apksignerPath,
      nativeLibraryPageAlignmentKb:
          nativeLibraryPageAlignmentKb ?? this.nativeLibraryPageAlignmentKb,
      signingScheme: signingScheme ?? this.signingScheme,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'keystorePath': keystorePath,
      'keyAlias': keyAlias,
      'storePassword': storePassword,
      'keyPassword': keyPassword,
      'remark': remark,
      'zipalignPath': zipalignPath,
      'apksignerPath': apksignerPath,
      'nativeLibraryPageAlignmentKb': nativeLibraryPageAlignmentKb,
      'signingScheme': signingScheme.name,
    };
  }

  factory AndroidSigningConfig.fromJson(Map<String, Object?> json) {
    final keyAlias = (json['keyAlias'] as String? ?? '').trim();

    return AndroidSigningConfig(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? keyAlias,
      keystorePath: json['keystorePath'] as String? ?? '',
      keyAlias: keyAlias,
      storePassword: json['storePassword'] as String? ?? '',
      keyPassword: json['keyPassword'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      zipalignPath: json['zipalignPath'] as String? ?? '',
      apksignerPath: json['apksignerPath'] as String? ?? '',
      nativeLibraryPageAlignmentKb:
          json['nativeLibraryPageAlignmentKb'] as int? ?? 16,
      signingScheme: AndroidSigningScheme.fromName(
        json['signingScheme'] as String?,
      ),
    );
  }
}
