enum HardeningArtifactType {
  apk('APK', '.apk'),
  aab('AAB', '.aab'),
  sharedObject('SO', '.so'),
  androidProject('源码工程', '');

  const HardeningArtifactType(this.label, this.extension);

  final String label;
  final String extension;
}

class HardeningArtifactInspection {
  const HardeningArtifactInspection({
    required this.type,
    required this.path,
    this.abi,
    this.moduleNames = const [],
  });

  final HardeningArtifactType type;
  final String path;
  final String? abi;
  final List<String> moduleNames;
}

class HardeningArtifactException implements Exception {
  const HardeningArtifactException(this.message);

  final String message;

  @override
  String toString() => message;
}
