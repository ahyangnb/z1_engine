import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/models/channel_package_config.dart';

void main() {
  test('preserves leading zero width from the start index text', () {
    const config = ChannelPackageConfig(
      prefix: 'BUKE',
      count: 2,
      startIndex: 1,
      startIndexText: '0001',
    );

    expect(config.channelCodeAt(0), 'BUKE0001');
    expect(config.channelCodeAt(1), 'BUKE0002');
  });

  test(
    'keeps the existing three digit default when no leading zero is typed',
    () {
      const config = ChannelPackageConfig(
        prefix: 'BUKE',
        count: 2,
        startIndex: 1,
        startIndexText: '1',
      );

      expect(config.channelCodeAt(0), 'BUKE001');
      expect(config.channelCodeAt(1), 'BUKE002');
    },
  );
}
