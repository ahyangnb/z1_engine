import 'package:flutter/material.dart';
import 'package:z1_engine/core/models/package_target.dart';
import 'package:z1_engine/shared/widgets/display_field.dart';
import 'package:z1_engine/shared/widgets/form_grid.dart';

class PackageForm extends StatelessWidget {
  const PackageForm({super.key, required this.target});

  final PackageTarget target;

  @override
  Widget build(BuildContext context) {
    final title = target == PackageTarget.android
        ? 'Android 出新包'
        : 'Flutter 出新包';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const FormGrid(
          children: [
            DisplayField(label: '包名', hint: 'com.example.app'),
            DisplayField(label: '版本名', hint: '1.0.0'),
            DisplayField(label: '版本号', hint: '100'),
            DisplayField(label: '输出目录', hint: '/build/release'),
            DisplayField(label: '渠道', hint: 'official'),
            DisplayField(label: '备注', hint: '本次出包说明'),
          ],
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('生成新包'),
          ),
        ),
      ],
    );
  }
}
