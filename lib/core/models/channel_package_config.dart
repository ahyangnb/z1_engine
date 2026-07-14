class ChannelPackageConfig {
  const ChannelPackageConfig({
    this.outputDirectory = '',
    this.prefix = 'ch',
    this.count = 5,
    this.startIndex = 1,
    this.startIndexText = '1',
  });

  final String outputDirectory;
  final String prefix;
  final int count;
  final int startIndex;
  final String startIndexText;

  String channelCodeAt(int zeroBasedIndex) {
    final currentIndex = startIndex + zeroBasedIndex;
    return '$prefix${currentIndex.toString().padLeft(sequenceWidth, '0')}';
  }

  int get sequenceWidth {
    final normalizedStartIndexText = startIndexText.trim();
    if (normalizedStartIndexText.startsWith('0')) {
      return normalizedStartIndexText.length;
    }

    return normalizedStartIndexText.length > 3
        ? normalizedStartIndexText.length
        : 3;
  }

  Map<String, Object?> toJson() {
    return {
      'outputDirectory': outputDirectory,
      'prefix': prefix,
      'count': count,
      'startIndex': startIndex,
      'startIndexText': startIndexText,
    };
  }

  factory ChannelPackageConfig.fromJson(Map<String, Object?> json) {
    final startIndex = json['startIndex'] as int? ?? 1;
    final startIndexText = (json['startIndexText'] as String?)?.trim();

    return ChannelPackageConfig(
      outputDirectory: json['outputDirectory'] as String? ?? '',
      prefix: json['prefix'] as String? ?? 'ch',
      count: json['count'] as int? ?? 5,
      startIndex: startIndex,
      startIndexText: startIndexText == null || startIndexText.isEmpty
          ? startIndex.toString()
          : startIndexText,
    );
  }
}
