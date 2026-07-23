class CodeTransparencySigningConfig {
  const CodeTransparencySigningConfig({
    required this.id,
    required this.name,
    required this.keystorePath,
    required this.keyAlias,
    required this.storePassword,
    required this.keyPassword,
    this.remark = '',
  });

  final String id;
  final String name;
  final String keystorePath;
  final String keyAlias;
  final String storePassword;
  final String keyPassword;
  final String remark;

  String get effectiveKeyPassword {
    return keyPassword.isEmpty ? storePassword : keyPassword;
  }

  CodeTransparencySigningConfig copyWith({
    String? name,
    String? keystorePath,
    String? keyAlias,
    String? storePassword,
    String? keyPassword,
    String? remark,
  }) {
    return CodeTransparencySigningConfig(
      id: id,
      name: name ?? this.name,
      keystorePath: keystorePath ?? this.keystorePath,
      keyAlias: keyAlias ?? this.keyAlias,
      storePassword: storePassword ?? this.storePassword,
      keyPassword: keyPassword ?? this.keyPassword,
      remark: remark ?? this.remark,
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
    };
  }

  factory CodeTransparencySigningConfig.fromJson(Map<String, Object?> json) {
    final keyAlias = (json['keyAlias'] as String? ?? '').trim();
    return CodeTransparencySigningConfig(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? keyAlias,
      keystorePath: json['keystorePath'] as String? ?? '',
      keyAlias: keyAlias,
      storePassword: json['storePassword'] as String? ?? '',
      keyPassword: json['keyPassword'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
    );
  }
}
