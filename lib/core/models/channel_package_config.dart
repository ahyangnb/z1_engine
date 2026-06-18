class ChannelPackageConfig {
  const ChannelPackageConfig({
    this.outputDirectory = '',
    this.prefix = 'ch',
    this.count = 10,
    this.startIndex = 1,
  });

  final String outputDirectory;
  final String prefix;
  final int count;
  final int startIndex;

  Map<String, Object?> toJson() {
    return {
      'outputDirectory': outputDirectory,
      'prefix': prefix,
      'count': count,
      'startIndex': startIndex,
    };
  }

  factory ChannelPackageConfig.fromJson(Map<String, Object?> json) {
    return ChannelPackageConfig(
      outputDirectory: json['outputDirectory'] as String? ?? '',
      prefix: json['prefix'] as String? ?? 'ch',
      count: json['count'] as int? ?? 10,
      startIndex: json['startIndex'] as int? ?? 1,
    );
  }
}
