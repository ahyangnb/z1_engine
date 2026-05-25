import 'package:flutter/material.dart';
import 'package:z1_engine/core/models/package_target.dart';

class TargetTabs extends StatelessWidget {
  const TargetTabs({
    super.key,
    required this.selected,
    required this.androidLabel,
    required this.flutterLabel,
    required this.onSelected,
  });

  final PackageTarget selected;
  final String androidLabel;
  final String flutterLabel;
  final ValueChanged<PackageTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PackageTarget>(
      segments: [
        ButtonSegment<PackageTarget>(
          value: PackageTarget.android,
          label: Text(androidLabel),
          icon: const Icon(Icons.android_outlined),
        ),
        ButtonSegment<PackageTarget>(
          value: PackageTarget.flutter,
          label: Text(flutterLabel),
          icon: const Icon(Icons.flutter_dash_outlined),
        ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onSelected(values.first),
    );
  }
}
